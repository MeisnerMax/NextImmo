# P0 Reference Slice Specification

Status: `proposed`

## Slice

`Authentication -> Workspace -> Property list -> Property detail -> Property mutation -> Audit -> Realtime`

## Scope

| ID | Capability | Owner | Status |
|---|---|---|---|
| REF-001 | Supabase authentication session | identity_access | proposed |
| REF-002 | Active workspace membership | identity_access | proposed |
| REF-003 | Workspace-scoped property list | portfolio_property | proposed |
| REF-004 | Workspace-scoped property detail | portfolio_property | proposed |
| REF-005 | Optimistic-concurrency property update | portfolio_property | proposed |
| REF-006 | Append-only audit event | platform_audit_jobs | proposed |
| REF-007 | Realtime refresh for authorized workspace clients | portfolio_property | proposed |

## Existing Evidence

| ID | Evidence | Finding | Status |
|---|---|---|---|
| EVD-REF-001 | `lib/main.dart` | SQLite FFI is initialized before app start. | verified |
| EVD-REF-002 | `lib/ui/state/security_state.dart`, `lib/ui/navigation/app_navigation.dart` | P1-008 is started: missing state resolves to no role and unknown roles receive no global page access. | verified |
| EVD-REF-003 | `lib/core/security/rbac.dart` | Local permission vocabulary is default-deny for unknown roles. | verified |
| EVD-REF-004 | `lib/data/repositories/permission_guard.dart` | Authorization is process-local, not server-enforced. | verified |
| EVD-REF-005 | `lib/core/models/property.dart` | Current property model has no workspace, actor or version fields. | verified |
| EVD-REF-006 | `lib/data/repositories/audit_log_repo.dart` | Audit supports workspace, actor, correlation and diffs but remains SQLite-local. | verified |

## Cloud Contract

### Workspace

Required fields: `id`, `name`, `created_at`, `updated_at`, `version`.

The workspace is the tenancy root and therefore does not carry a self-referencing `workspace_id`; all workspace-owned child entities do. `[proposed]`

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

## Exclusions

- Offline write queue
- document storage
- bulk import
- portfolio analytics
- legacy SQLite removal
- production Supabase provisioning
