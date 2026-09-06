-- PROPERTY-ACTIVITY-03 (V-2a): rent components reach the property chronicle.
--
-- LEASING-COMPONENTS-01 writes `lease_component.create`, `.update` and
-- `.close` into `audit_events`. Without this migration those rows exist and
-- are invisible: `private.property_activity_rows` resolves an event to a
-- property by naming each entity type, and an unnamed type matches nothing.
-- The chronicle would show a lease whose rent changed and no record of the
-- change — which is worse than showing nothing, because it looks complete.
--
-- The reason a package is needed at all is that `finish_leasing_mutation`
-- writes no `parent_entity_*`. PROPERTY-ACTIVITY-01 established that ten of
-- the twelve audit-writing migrations leave those columns null, and chose to
-- resolve through the source aggregate rather than widen every writer. This
-- follows that decision; it does not reopen it.
--
-- Two functions are replaced and nothing is created, so the rollback has no
-- object whose absence proves it — the same unusual shape as
-- PROPERTY-ACTIVITY-02's and FINANCE-01c's. `public.property_activity` is
-- deliberately **not** touched: it consumes the taxonomy and the row set and
-- enumerates no entity type of its own, so replacing it would only be a way
-- to introduce drift.
--
-- Both functions are reproduced from their current definitions
-- (`20260914100000_property_activity_02_finance.sql`, the newest migration
-- that declares them) with exactly one clause added to each. SR-20 and SR-22
-- are unchanged: no new function, no new policy.

create or replace function private.property_activity_taxonomy()
returns table (
  entity_type text,
  domain text,
  required_permission text
)
language sql
immutable
security definer
set search_path = ''
as $function$
  values
    -- The property record itself, and its pictures: both `property.read`,
    -- which the caller must already hold to reach this function at all.
    ('property', 'property', 'property.read'),
    ('property_media', 'property', 'property.read'),
    -- Leasing. Units, contracts, the pipeline and frozen rent rolls share one
    -- read gate because the domain does.
    ('unit', 'leasing', 'lease.read'),
    ('lease', 'leasing', 'lease.read'),
    ('leasing_case', 'leasing', 'lease.read'),
    ('rent_roll_snapshot', 'leasing', 'lease.read'),
    ('lease_component', 'leasing', 'lease.read'),
    -- Operations: three separately gated sub-areas, exactly as `Betrieb` is.
    ('maintenance_ticket', 'maintenance', 'maintenance.read'),
    ('capex_project', 'capex', 'capex.read'),
    ('task', 'tasks', 'task.read'),
    -- Documents and compliance.
    ('document', 'documents', 'document.read'),
    ('document_version', 'documents', 'document.read'),
    ('document_link', 'documents', 'document.read'),
    ('required_document', 'documents', 'document.read'),
    -- Valuation. Never a value, only that a case moved.
    ('valuation_case', 'valuation', 'valuation.read'),
    -- Finance. Only the ledger entry: it is the one finance record that
    -- carries a `property_id`. `finance_account`, `finance_period` and
    -- `finance_kpi_definition` are workspace-level rows with no property tie
    -- of any kind, so there is no honest way to place them in ONE property's
    -- chronicle -- every property would have to claim the same event.
    ('finance_ledger_entry', 'finance', 'finance.read')
$function$;

create or replace function private.property_activity_rows(
  p_workspace_id uuid,
  p_property_id uuid
)
returns table (audit_event_id uuid)
language sql
stable
security definer
set search_path = ''
as $function$
  select event.id
  from public.audit_events as event
  where event.workspace_id = p_workspace_id
    and event.entity_id is not null
    and (
      -- The property row itself.
      (event.entity_type = 'property' and event.entity_id = p_property_id)
      -- Media.
      or (
        event.entity_type = 'property_media'
        and exists (
          select 1 from public.property_media as media
          where media.workspace_id = p_workspace_id
            and media.id = event.entity_id
            and media.property_id = p_property_id
        )
      )
      -- Leasing.
      or (
        event.entity_type = 'unit'
        and exists (
          select 1 from public.units as unit
          where unit.workspace_id = p_workspace_id
            and unit.id = event.entity_id
            and unit.property_id = p_property_id
        )
      )
      or (
        event.entity_type = 'lease'
        and exists (
          select 1 from public.leases as lease
          where lease.workspace_id = p_workspace_id
            and lease.id = event.entity_id
            and lease.property_id = p_property_id
        )
      )
      or (
        event.entity_type = 'leasing_case'
        and exists (
          select 1 from public.leasing_cases as leasing_case
          where leasing_case.workspace_id = p_workspace_id
            and leasing_case.id = event.entity_id
            and leasing_case.property_id = p_property_id
        )
      )
      or (
        event.entity_type = 'rent_roll_snapshot'
        and exists (
          select 1 from public.rent_roll_snapshots as snapshot
          where snapshot.workspace_id = p_workspace_id
            and snapshot.id = event.entity_id
            and snapshot.property_id = p_property_id
        )
      )
      -- The only two-hop resolution in this function: a component has no
      -- property of its own and never should -- it belongs to a lease, and the
      -- lease is what sits on a property. Denormalising `property_id` onto the
      -- component would create a second answer to "which property is this?"
      -- that could disagree with the first.
      or (
        event.entity_type = 'lease_component'
        and exists (
          select 1
          from public.lease_components as component
          join public.leases as lease
            on lease.workspace_id = component.workspace_id
            and lease.id = component.lease_id
          where component.workspace_id = p_workspace_id
            and component.id = event.entity_id
            and lease.property_id = p_property_id
        )
      )
      -- Operations.
      or (
        event.entity_type = 'maintenance_ticket'
        and exists (
          select 1 from public.maintenance_tickets as ticket
          where ticket.workspace_id = p_workspace_id
            and ticket.id = event.entity_id
            and ticket.property_id = p_property_id
        )
      )
      or (
        event.entity_type = 'capex_project'
        and exists (
          select 1 from public.capex_projects as project
          where project.workspace_id = p_workspace_id
            and project.id = event.entity_id
            and project.property_id = p_property_id
        )
      )
      or (
        event.entity_type = 'task'
        and exists (
          select 1 from public.tasks as task
          where task.workspace_id = p_workspace_id
            and task.id = event.entity_id
            and task.property_id = p_property_id
        )
      )
      -- Documents reach a property through their link, not through a column.
      or (
        event.entity_type = 'document'
        and exists (
          select 1 from public.document_links as link
          where link.workspace_id = p_workspace_id
            and link.document_id = event.entity_id
            and link.entity_type = 'property'
            and link.entity_id = p_property_id
        )
      )
      or (
        event.entity_type = 'document_version'
        and exists (
          select 1
          from public.document_versions as document_version
          join public.document_links as link
            on link.workspace_id = document_version.workspace_id
            and link.document_id = document_version.document_id
          where document_version.workspace_id = p_workspace_id
            and document_version.id = event.entity_id
            and link.entity_type = 'property'
            and link.entity_id = p_property_id
        )
      )
      or (
        event.entity_type = 'document_link'
        and exists (
          select 1 from public.document_links as link
          where link.workspace_id = p_workspace_id
            and link.id = event.entity_id
            and link.entity_type = 'property'
            and link.entity_id = p_property_id
        )
      )
      or (
        event.entity_type = 'required_document'
        and exists (
          select 1 from public.required_documents as requirement
          where requirement.workspace_id = p_workspace_id
            and requirement.id = event.entity_id
            and requirement.entity_type = 'property'
            and requirement.entity_id = p_property_id
        )
      )
      -- Valuation.
      or (
        event.entity_type = 'valuation_case'
        and exists (
          select 1 from public.valuation_cases as valuation_case
          where valuation_case.workspace_id = p_workspace_id
            and valuation_case.id = event.entity_id
            and valuation_case.property_id = p_property_id
        )
      )
      -- Finance. Ledger entries only; see the taxonomy for why the other
      -- three finance entity types cannot be attributed to a property.
      or (
        event.entity_type = 'finance_ledger_entry'
        and exists (
          select 1 from public.finance_ledger_entries as ledger_entry
          where ledger_entry.workspace_id = p_workspace_id
            and ledger_entry.id = event.entity_id
            and ledger_entry.property_id = p_property_id
        )
      )
    )
$function$;
