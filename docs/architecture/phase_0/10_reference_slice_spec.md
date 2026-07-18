# P0 Reference Slice Specification

Status: `partial`; lokal inklusive Runtime, Deep Links, bedienbarer passwordless Auth/TOTP und Property-AAL2 verifiziert; Entitlement-/Staging-Gates offen.

## Slice

`Authentication -> Workspace -> Property list -> Property detail -> Property mutation -> Audit -> Realtime`

## Scope

| ID | Capability | Owner | Status |
|---|---|---|---|
| REF-001 | Supabase authentication session | identity_access | verified |
| REF-002 | Active workspace membership | identity_access | verified |
| REF-003 | Workspace-scoped property list | portfolio_property | verified |
| REF-004 | Workspace-scoped property detail | portfolio_property | verified |
| REF-005 | Optimistic-concurrency property update | portfolio_property | verified |
| REF-006 | Append-only audit event | platform_audit_jobs | verified |
| REF-007 | Realtime refresh for authorized workspace clients | portfolio_property | verified |

## Existing Evidence

| ID | Evidence | Finding | Status |
|---|---|---|---|
| EVD-REF-001 | `lib/main.dart`, `lib/app.dart` | Explizite Umgebungsauswahl initialisiert ausschliesslich SQLite oder Supabase und verdrahtet die passenden Provider. | verified |
| EVD-REF-002 | `lib/ui/state/security_state.dart`, `lib/ui/navigation/app_navigation.dart` | P1-008 ist abgeschlossen: fehlender State liefert keine Rolle und unbekannte Rollen erhalten keinen globalen Seitenzugriff. | verified |
| EVD-REF-003 | `lib/core/security/rbac.dart` | Local permission vocabulary is default-deny for unknown roles. | verified |
| EVD-REF-004 | `lib/data/repositories/permission_guard.dart`, `supabase/migrations/20260712160000_p1_003_default_deny_rls.sql` | Legacy-Authorization bleibt lokal; der Cloud-Schnitt wird serverseitig durch Default-Deny-RLS geschuetzt. | verified |
| EVD-REF-005 | `lib/core/models/property.dart`, `lib/features/portfolio_property/domain/property_dto.dart` | Das Legacy-Modell bleibt unveraendert; der Cloud-DTO fuehrt Workspace, Actor und Version. | verified |
| EVD-REF-006 | `lib/data/repositories/audit_log_repo.dart`, `supabase/migrations/20260712170000_p1_004_property_contract.sql` | Legacy-Audit bleibt lokal; Cloud-Mutationen schreiben atomar append-only Audit-Events. | verified |
| EVD-REF-007 | `lib/features/reference_slice/`, `test/features/reference_slice/`, `test/integration/supabase_property_realtime_integration_test.dart` | Application-State, adaptive UI und lokaler Mehrclient-Realtime-Fluss sind implementiert und getestet. | verified |
| EVD-REF-008 | `lib/ui/navigation/app_navigation.dart`, `test/app_runtime_test.dart` | Stabile `/properties`- und `/properties/:id`-Routen funktionieren auch beim Kaltstart ohne doppelten Route-Stack. | verified |
| EVD-REF-009 | `supabase/migrations/20260718100000_p1_015_aal_hardening.sql`, `test/integration/support/supabase_mfa_test_helper.dart` | Property-Mutation verlangt serverseitig AAL2; echter lokaler TOTP-Flow weist AAL1-Deny und AAL2-Erfolg nach. | verified_local |
| EVD-REF-010 | `lib/features/identity_access/`, `lib/features/reference_slice/`, `test/integration/supabase_property_repository_integration_test.dart` | Passwordless-PKCE-Anforderung, TOTP-Enrollment/Step-up und lokaler Logout sind bedienbar und lokal gegen Supabase verifiziert. | verified_local |

## Cloud Contract

### Workspace

Required fields: `id`, `name`, `created_at`, `updated_at`, `version`.

The workspace is the tenancy root and therefore does not carry a self-referencing `workspace_id`; all workspace-owned child entities do. `[verified]`

### Membership

Required fields: `id`, `workspace_id`, `user_id`, `role`, `status`, `created_at`, `updated_at`, `version`.

Invariant: one active membership per `(workspace_id, user_id)`.

### Property

Required fields: `id`, `workspace_id`, `name`, address fields, `property_type`, `status`, `created_at`, `updated_at`, `created_by`, `updated_by`, `version`, optional `deleted_at`.

Invariant: every read and mutation requires an active membership for `workspace_id`.

### Property Update Command

Input: authenticated user, workspace id, property id, expected version, mutation id, changed fields, optional reason.

Atomic result:

1. Validate membership and `property.update` permission.
2. Reject workspace mismatch.
3. Reject stale expected version with conflict response.
4. Update property and increment version.
5. Insert immutable audit event with old/new values and mutation id.
6. Commit once; Realtime emits only committed state.

## RLS Acceptance Criteria

| ID | Criterion |
|---|---|
| AC-RLS-001 | Anonymous access returns no workspace, membership, property or audit rows. |
| AC-RLS-002 | User A cannot read or mutate User B's workspace data. |
| AC-RLS-003 | Inactive membership grants no access. |
| AC-RLS-004 | Viewer can read properties but cannot mutate them. |
| AC-RLS-005 | Authorized manager can mutate only properties in the active workspace. |
| AC-RLS-006 | Direct API calls obey the same rules as the Flutter client. |

## Functional Acceptance Criteria

| ID | Criterion |
|---|---|
| AC-REF-001 | A valid session loads only workspaces with active membership. |
| AC-REF-002 | Selecting a workspace loads only its non-deleted properties. |
| AC-REF-003 | Property detail is addressable by stable route and ID. |
| AC-REF-004 | A successful update increments version exactly once. |
| AC-REF-005 | Retrying the same mutation id does not duplicate update or audit event. |
| AC-REF-006 | A stale expected version returns a structured conflict without data loss. |
| AC-REF-007 | A second authorized client observes the committed update. |
| AC-REF-008 | Every successful mutation has exactly one correlated audit event. |
| AC-REF-009 | Loading, empty, error, unauthenticated and forbidden states are explicit. |

## Form Factors

| Platform | Required behavior |
|---|---|
| Desktop/Web | Persistent navigation, searchable property table, side-by-side detail where width permits. |
| Tablet | Adaptive list/detail navigation with touch targets and no horizontal overflow. |
| Phone | Separate property list and detail routes; mutation form vertically stacked. |

## Test Set

- PostgreSQL migration apply/rollback in disposable database.
- RLS positive and negative tests with at least two users and two workspaces.
- Repository contract tests against local adapter and Supabase adapter.
- Flutter state tests for unauthenticated, forbidden, conflict and retry states.
- Responsive widget tests at phone, tablet and desktop widths.
- End-to-end test with two authorized sessions verifying Realtime refresh.

## Current Gate Evidence

| ID | Status | Evidence / gap |
|---|---|---|
| AC-RLS-001 | verified | Anonymous table/RPC access is denied by grants and pgTAP. |
| AC-RLS-002 | verified | Two-workspace read/write isolation passes in pgTAP and real client tests. |
| AC-RLS-003 | verified | Suspended membership cannot read Property/Audit or update through RPC. |
| AC-RLS-004 | verified | Viewer reads but receives `forbidden` for mutation. |
| AC-RLS-005 | verified | Manager mutation is workspace-scoped and foreign IDs fail closed. |
| AC-RLS-006 | partial | SQL and Supabase-Flutter client paths pass; a raw PostgREST parity test is open. |
| AC-REF-001 | verified | Session/AAL and active memberships are mapped fail-closed. |
| AC-REF-002 | verified | List query filters workspace and tombstones. |
| AC-REF-003 | verified | Stable ID detail and `/properties/:id` cold-start deep-link wiring pass in `test/app_runtime_test.dart`. |
| AC-REF-004 | verified | Successful RPC increments version exactly once. |
| AC-REF-005 | verified | Identical mutation retry returns the stored result without duplicate audit. |
| AC-REF-006 | verified | Stale version returns structured conflict and current property. |
| AC-REF-007 | verified | Local authorized second client observes committed update. |
| AC-REF-008 | verified | Exactly one audit event preserves actor and correlation ID. |
| AC-REF-009 | verified | Controller/UI tests cover loading, empty, error, unauthenticated and forbidden states. |

Der lokale Teststand umfasst 196 pgTAP, Rollback, Concurrency, echte passwordless-PKCE-/AAL2-Adapter-/Mehrclientgates, Controller-, responsive Widget-/Golden- und Kaltstart-Deep-Link-Tests. Allgemeine privilegierte MFA/Rollenpolicy, Entitlement-Revalidation, Staging-E2E und Performancebudgets bleiben offen; Details: `docs/architecture/phase_1/03_reference_slice_gate_review.md`.

## Exclusions

- Offline write queue
- document storage
- bulk import
- portfolio analytics
- legacy SQLite removal
- production Supabase provisioning
