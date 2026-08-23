# Enterprise Target Architecture

## Current State

NexImmo runs today as a Flutter desktop/web application with a Supabase (PostgreSQL) data layer as its only runtime backend (`DEC-024`, 2026-08-06; SQLite removed as a runtime backend in `AP-X02-2b`, 2026-08-08), Riverpod state management, repository-based data access, and workflow-heavy screens for valuation, operations, documents, tasks, and reporting. The current strengths are:

- workspace-scoped, RLS-protected cloud data access behind backend-agnostic repository contracts
- clear separation between UI, repository, and core calculation engines
- migration-based schema evolution
- growing workspace, security, operations, and audit foundations

Current technical limitations that matter for enterprise expansion:

- permissions were historically coarse-grained
- audit coverage and structure were not fully uniform across critical mutations
- approval workflows were not first-class in the data model
- object scopes such as workspace, property, and portfolio were only partially expressed
- cloud-readiness metadata and sync boundaries were still implicit in several modules

## Target State

NexImmo evolves into a hybrid enterprise platform with these characteristics:

- Supabase/PostgreSQL is the single data layer (`DEC-024`); desktop and web clients consume it through backend-agnostic repository contracts
- no offline or local-core mode is promised; offline/sync is out of scope unless re-decided (`DEC-024` withdrew the offline commitment)
- permissions are expressed as fine-grained capabilities, not only broad roles
- critical mutations are repository- or service-driven, validated, and audit-ready
- approval and review workflows are visible in the data model and UI
- cross-module operations workflows connect properties, units, leases, tenants, alerts, tasks, and documents
- audit, reporting, exports, imports, and integration jobs are structurally consistent

## Client Core And Cloud Layer

### Client Core

The client core owns:

- deterministic engines for valuation, rent roll, quality, covenants, reports, and operations
- repository contracts under `lib/features/<feature>/application` (no SDK types) and their Supabase adapters under `lib/features/<feature>/data`
- UI state and interaction flows

(Until `DEC-024`/`AP-X02-2b` this section also listed SQLite persistence, offline repositories, local session/workspace handling and file-based documents; those responsibilities moved to the cloud layer or were retired.)

### Cloud Layer (current: Supabase)

The cloud layer is the present runtime, not a future add-on. It owns today:

- persistence and versioned migrations (`supabase/migrations/`)
- identity and MFA (Supabase Auth: email + password → `aal1` → TOTP → `aal2`; AAL2 is the server-side boundary for the whole workspace business surface, `DEC-025`)
- workspace scoping, memberships, default-deny RLS and the permission helper
- private document storage behind short-lived signed URLs (`P2-D03`)
- realtime invalidation and entitlement revalidation signals (`DEC-018`, `DEC-022`)

Responsibilities still expected to be added later, through explicit abstractions instead of bypassing repositories:

- identity federation and SSO
- workspace and tenant provisioning
- synchronization and conflict coordination
- background jobs and scheduled scans
- webhooks and integration jobs
- cross-user collaboration and review threads

The cloud layer must consume or implement service boundaries rather than creating parallel data rules.

## Module Responsibilities

### `core/`

- business engines, calculations, validation, workflow rules, and shared domain policies
- no direct UI knowledge
- no direct widget dependencies

### `features/<feature>/application` and `features/<feature>/data`

- only entry point for critical mutations and persisted reads: repository contracts (application) implemented by Supabase adapters (data)
- query composition, RPC-based mutation, validation orchestration, audit correlation, and invalidation handling
- no direct widget rendering logic

### `data/repositories/` and `data/sqlite/` (legacy, non-runtime)

- the former sqflite-backed repositories and schema bootstrapping; no longer reachable from the application runtime (`AP-X02-2b`), retained only for migration/cutover/test tooling until `AP-X02-9` removes them
- runtime schema evolution lives in `supabase/migrations/`

### `ui/state/`

- screen-level orchestration, refresh flows, selected entity state, and async coordination
- no direct SQL access

### `ui/screens/`

- presentation, interaction, navigation, and user feedback
- must depend on repositories/providers instead of raw database calls

## Entity Lifecycles

### Property

`created -> active -> archived`

Properties are top-level business containers. Child entities such as scenarios, units, leases, tenants, rent roll lines, alerts, tasks, and documents must remain referentially connected to a property context.

### Scenario

`draft -> in_review -> approved/rejected -> archived`

If an approved scenario is changed by a non-approval mutation, the scenario returns to `draft` and is marked as changed since approval. Approval metadata remains historically visible.

### Operations Entities

- Unit: `vacant/occupied/offline` plus operational vacancy metadata
- Lease: `draft/future/active/terminated/expired`
- Tenant: `prospect/active/inactive` through operational context rather than one hard global state

Operational issues can create alerts, and alerts can create tasks.

### Document

`uploaded -> pending_review -> verified/rejected -> expired`

Documents remain attached to business entities and later may also point to cloud object references and version chains.

### Task

`open -> in_progress -> resolved/dismissed/escalated`

Tasks should always preserve entity context where possible.

## Permission Model

Permissions are defined as explicit capabilities such as:

- `property.read`, `property.update`, `property.delete`
- `scenario.read`, `scenario.update`, `scenario.approve`
- `document.verify`
- `task.assign`, `task.resolve`
- `audit.read`
- `security.manage`

Roles aggregate permissions. Current enterprise target roles:

- `admin`
- `manager`
- `analyst`
- `operations`
- `viewer`

Scope-readiness is required from the model onward. A permission decision may later be constrained by:

- workspace
- property
- portfolio
- region

Workspace scope is enforced server-side today (default-deny RLS, membership-bound permissions, AAL2 for the whole workspace business surface per `DEC-025`); property, portfolio and region scoping are not yet implemented, and every new permission-sensitive feature must be shaped so those finer scopes can be added without API breakage.

## Audit Concept

Critical mutations should write uniform audit events with:

- workspace and actor context
- entity and optional parent entity references
- action
- old and new values
- source
- optional reason and correlation id
- system-event marker

Audit records are append-only from the product perspective:

- no normal delete path
- no edit UI
- exportable but not mutable

Property-scoped audit views must load only relevant events for the property and its business children.

## API, Sync, And Integration Strategy

Future integrations should sit behind explicit boundaries:

- identity provider abstraction
- document storage abstraction
- sync service abstraction
- import/export job abstraction
- webhook event abstraction

Every new critical entity should increasingly carry metadata that helps later sync and cloud usage:

- created/updated timestamps
- actor metadata where reasonable
- source system markers
- future-ready version or concurrency token fields

## Technical Guardrails

These rules are binding for ongoing enterprise work:

1. No direct SQL access from UI code.
2. Every critical mutation goes through a repository or dedicated service.
3. Every critical mutation should be audit-ready, and most must write audit records.
4. Every workflow entity needs explicit status logic.
5. Every new core model change must carry workspace scoping, actor metadata and version/concurrency tokens and must be enforceable server-side (RLS, AAL2 per `DEC-025`).
