# NexImmo Screen Specification Template

Use one copy of this template per planned screen under:

`docs/product/screens/<screen_slug>.md`

The planning chat owns this document until the specification is implementation-ready. The implementation chat must not silently reinterpret missing product decisions.

---

# <SCREEN NAME>

## Metadata

- Package / screen ID:
- Domain:
- Route:
- Current implementation file(s):
- Planning status: DRAFT / REVIEW / APPROVED
- Dependencies:
- Related screens:

## 1. Purpose

What is this screen for? What business problem does it solve?

## 2. Primary users and jobs

For each relevant user/role:

- what are they trying to accomplish?
- what information do they need first?
- what decisions/actions happen here?

## 3. Entry points and navigation

- How does the user reach the screen?
- Which screens can they navigate to from here?
- What context/selection is preserved?
- Deep-link behavior if applicable.

## 4. Information architecture

Describe the hierarchy in reading/working order.

Example:

1. Page header
2. Primary status / summary
3. Key actions
4. Main content/list/detail
5. Secondary information
6. Activity/history/supporting information

## 5. Layout and interaction model

Define:

- desktop layout
- tablet behavior
- mobile behavior
- page header
- tabs/sections
- tables/cards
- drawers/modals where justified
- sticky areas/actions if any
- selection behavior
- pagination/infinite-scroll behavior if any

Follow `PRODUCT-UX-FOUNDATION-01`; do not invent a separate design language.

## 6. Functional requirements

List every user-visible function explicitly.

For each action specify:

- trigger
- prerequisites
- validation
- success behavior
- failure behavior
- permission requirement
- resulting navigation/state change

Examples:

- create
- edit
- archive/delete
- assign
- upload/download
- filter
- sort
- search
- export
- bulk action
- status transition

## 7. Data requirements

For every displayed/edited value:

- field/domain meaning
- source repository/table/view
- required vs optional
- editable vs read-only
- formatting
- relationships

Do not invent schema changes here. Put missing capabilities under Backend Gaps.

## 8. Permissions and security behavior

Specify:

- route/screen visibility
- read permission
- per-action permission
- disabled vs hidden behavior
- RLS expectations
- AAL requirements if relevant
- behavior when authorization changes during the session

Client gating never replaces server-side RLS/authorization.

## 9. Realtime / freshness behavior

If relevant:

- subscribed entity/events
- what updates live
- what requires reconcile/readback
- behavior after reconnect
- behavior when `liveUpdatesDegraded`
- canonical REST/read path

## 10. Screen states

Define expected UI for at least applicable states:

- initial loading
- background refresh
- empty
- populated
- partial/incomplete data
- validation error
- recoverable error
- fatal/unavailable error
- permission denied
- session/auth transition
- realtime degraded
- action in progress
- action success
- action failure

Avoid generic blank screens/spinners where useful state can remain visible.

## 11. Search / filter / sort

If applicable define:

- searchable fields
- filter dimensions
- default filters
- sorting options/default
- persistence of filter state
- URL/deep-link state if required
- empty-result behavior

## 12. Forms and validation

For every form:

- fields
- required/optional
- defaults
- input controls
- validation rules
- dependent fields
- unsaved changes behavior
- submission state
- server-validation mapping

## 13. Shared components

### Existing components to reuse

- ...

### Small extensions needed

- ...

### New shared component candidate

- ...

If a large shared redesign is required, create a separate shared-UI package instead of burying it in this screen.

## 14. Backend gaps

List anything the UI needs that current contracts do not provide.

For each gap:

- exact need
- affected domain/repository
- whether schema/RLS/permission changes may be required
- proposed separate package name

Implementation of an unapproved backend gap is out of scope for the screen agent.

## 15. Accessibility and usability

At minimum consider:

- keyboard navigation
- focus behavior
- labels/tooltips
- contrast
- screen-reader semantics where relevant
- touch target sizing
- destructive-action clarity

## 16. Analytics / audit / history

Only if the product requires it:

- audit event expectations
- activity/history display
- no secrets/sensitive payloads in logs

## 17. Test plan

Define expected coverage:

### Unit/application
- ...

### Widget/UI
- ...

### Repository/integration
- ...

### Staging E2E
- ...

Include negative permission/security paths where relevant.

## 18. Acceptance criteria

Use concrete observable criteria.

Examples:

- Given X, when Y, then Z.
- User with permission A can perform action B.
- User without permission A cannot access/read B.
- Reconnect causes one canonical reconcile, not a reload burst.

## 19. Out of scope

Explicitly list tempting adjacent work that this screen package will not do.

## 20. Open decisions

Planning cannot be APPROVED while material product decisions remain unresolved.

## 21. Implementation handoff

When APPROVED, summarize:

- exact scope
- key files/contracts likely involved
- dependencies that must already be on main
- known backend gaps handled separately
- required tests
- hard invariants that must not regress

The implementation chat must still inspect the actual current repository before changing code.
