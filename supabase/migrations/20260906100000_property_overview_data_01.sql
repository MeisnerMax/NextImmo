-- PROPERTY-OVERVIEW-DATA-01: the server-authoritative property overview.
--
-- One read that answers "what is the state of this asset, and what needs
-- attention" from the domains that actually have cloud contracts today. The
-- client never aggregates: the spec is explicit that a client-side roll-up
-- over paginated pages would be an invented number, and that a missing source
-- must not render as `0`, green or "complete".
--
-- Three rules shape this function:
--
--   1. Permission-scoped per section. A section the caller may not read is
--      absent from the payload (`available: false`), never zero. Leasing needs
--      `lease.read`, maintenance `maintenance.read`, CapEx `capex.read`, tasks
--      `task.read`, documents `document.read`, valuation `valuation.read`. The
--      property itself needs `property.read` with entity scope, exactly like
--      `update_property`.
--   2. Only stored facts. Every number is a count or a stored status, never a
--      derived rate: no occupancy percentage, no renewal risk, no NOI. Those
--      need their own definitions and, for finance, `P2-D08`. Counting rows a
--      status column already fixes is not a client-invented KPI; dividing them
--      into a rate would be a definition this package does not own.
--   3. `as_of` travels with the payload so the UI can state its freshness
--      instead of implying live truth.
--   4. Attention is ordered here, not in the client. The server picks which
--      facts warrant attention, assigns the severity and fixes the sequence;
--      the client renders that sequence. It is built from the permitted
--      sections only, so it cannot disclose records behind a missing
--      permission.
--
-- Deliberately NOT here: financial KPIs (`P2-D08`/`FINANCE-01`) and recent
-- activity (`AUDIT-01` read port). Their sections are absent, not empty.

create function public.property_overview(
  p_workspace_id uuid,
  p_property_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_today date := (v_now at time zone 'utc')::date;
  v_property public.properties%rowtype;
  v_result jsonb;
  v_section jsonb;
  v_attention jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  -- DEC-025: the whole workspace business surface sits behind aal2.
  if (auth.jwt() ->> 'aal') is distinct from 'aal2' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for the property overview'
      )
    );
  end if;

  if not private.has_scoped_entity_permission(
       p_workspace_id, 'property.read', 'property', p_property_id
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Property access is not permitted'
      )
    );
  end if;

  select property.*
  into v_property
  from public.properties as property
  where property.workspace_id = p_workspace_id
    and property.id = p_property_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  v_result := jsonb_build_object(
    'as_of', v_now,
    'property', jsonb_build_object(
      'id', v_property.id,
      'workspace_id', v_property.workspace_id,
      'name', v_property.name,
      'status', v_property.status,
      'version', v_property.version,
      'updated_at', v_property.updated_at
    )
  );

  -- --------------------------------------------------------------------------
  -- Leasing: stored unit states and lease states, plus contracts running out
  -- inside 90 days. No occupancy rate -- that definition belongs to the lease
  -- roll projection, not here.
  -- --------------------------------------------------------------------------
  if private.has_workspace_permission(p_workspace_id, 'lease.read') then
    select jsonb_build_object(
      'available', true,
      'units_total', count(*) filter (where true),
      'units_occupied', count(*) filter (where unit.status = 'occupied'),
      'units_vacant', count(*) filter (where unit.status = 'vacant'),
      'units_offline', count(*) filter (where unit.status = 'offline')
    )
    into v_section
    from public.units as unit
    where unit.workspace_id = p_workspace_id
      and unit.property_id = p_property_id;

    v_section := v_section || (
      select jsonb_build_object(
        'leases_active', count(*) filter (where lease.status = 'active'),
        'leases_ending_90d', count(*) filter (
          where lease.status = 'active'
            and lease.end_date is not null
            and lease.end_date between v_today and (v_today + 90)
        ),
        'leases_expired_open', count(*) filter (
          where lease.status = 'active'
            and lease.end_date is not null
            and lease.end_date < v_today
        )
      )
      from public.leases as lease
      where lease.workspace_id = p_workspace_id
        and lease.property_id = p_property_id
    );

    v_section := v_section || (
      select jsonb_build_object(
        'leasing_cases_open', count(*) filter (
          where leasing_case.status not in ('completed', 'cancelled')
        )
      )
      from public.leasing_cases as leasing_case
      where leasing_case.workspace_id = p_workspace_id
        and leasing_case.property_id = p_property_id
    );
  else
    v_section := jsonb_build_object('available', false, 'permission', 'lease.read');
  end if;
  v_result := jsonb_set(v_result, '{leasing}', v_section);

  -- --------------------------------------------------------------------------
  -- Maintenance: open tickets and how many are past their due date.
  -- --------------------------------------------------------------------------
  if private.has_workspace_permission(p_workspace_id, 'maintenance.read') then
    select jsonb_build_object(
      'available', true,
      'tickets_open', count(*) filter (
        where ticket.status not in ('resolved', 'invoiced', 'archived')
      ),
      'tickets_overdue', count(*) filter (
        where ticket.status not in ('resolved', 'invoiced', 'archived')
          and ticket.due_at is not null
          and ticket.due_at < v_now
      ),
      'tickets_urgent_open', count(*) filter (
        where ticket.status not in ('resolved', 'invoiced', 'archived')
          and ticket.priority = 'urgent'
      )
    )
    into v_section
    from public.maintenance_tickets as ticket
    where ticket.workspace_id = p_workspace_id
      and ticket.property_id = p_property_id;
  else
    v_section := jsonb_build_object(
      'available', false, 'permission', 'maintenance.read'
    );
  end if;
  v_result := jsonb_set(v_result, '{maintenance}', v_section);

  -- --------------------------------------------------------------------------
  -- CapEx: projects that are neither done nor cancelled.
  -- --------------------------------------------------------------------------
  if private.has_workspace_permission(p_workspace_id, 'capex.read') then
    select jsonb_build_object(
      'available', true,
      'projects_open', count(*) filter (
        where project.status not in ('completed', 'invoiced', 'archived')
      ),
      -- Before approval, in the enum order idea -> planned -> quote_requested
      -- -> approved. Not an invented state: these are the stored ones.
      'projects_before_approval', count(*) filter (
        where project.status in ('idea', 'planned', 'quote_requested')
      )
    )
    into v_section
    from public.capex_projects as project
    where project.workspace_id = p_workspace_id
      and project.property_id = p_property_id;
  else
    v_section := jsonb_build_object('available', false, 'permission', 'capex.read');
  end if;
  v_result := jsonb_set(v_result, '{capex}', v_section);

  -- --------------------------------------------------------------------------
  -- Tasks: the property roll-up TASK-QUERY-01 maintains server-side.
  -- --------------------------------------------------------------------------
  if private.has_workspace_permission(p_workspace_id, 'task.read') then
    select jsonb_build_object(
      'available', true,
      'tasks_open', count(*) filter (
        where task.status in ('open', 'in_progress', 'blocked')
      ),
      'tasks_overdue', count(*) filter (
        where task.status in ('open', 'in_progress', 'blocked')
          and task.due_at is not null
          and task.due_at < v_now
      ),
      'tasks_blocked', count(*) filter (where task.status = 'blocked')
    )
    into v_section
    from public.tasks as task
    where task.workspace_id = p_workspace_id
      and task.property_id = p_property_id;
  else
    v_section := jsonb_build_object('available', false, 'permission', 'task.read');
  end if;
  v_result := jsonb_set(v_result, '{tasks}', v_section);

  -- --------------------------------------------------------------------------
  -- Documents: the requirements the server already evaluates. Waived
  -- requirements are counted separately -- they are a decision, not a gap.
  -- --------------------------------------------------------------------------
  if private.has_workspace_permission(p_workspace_id, 'document.read') then
    select jsonb_build_object(
      'available', true,
      'requirements_total', count(*),
      'requirements_waived', count(*) filter (where requirement.waived_at is not null),
      'requirements_overdue', count(*) filter (
        where requirement.waived_at is null
          and requirement.due_at is not null
          and requirement.due_at < v_today
      )
    )
    into v_section
    from public.required_documents as requirement
    where requirement.workspace_id = p_workspace_id
      and requirement.entity_type = 'property'
      and requirement.entity_id = p_property_id;

    v_section := v_section || (
      select jsonb_build_object('documents_total', count(*))
      from public.documents as document
      join public.document_links as link
        on link.document_id = document.id
       and link.workspace_id = document.workspace_id
      where document.workspace_id = p_workspace_id
        and link.entity_type = 'property'
        and link.entity_id = p_property_id
    );
  else
    v_section := jsonb_build_object(
      'available', false, 'permission', 'document.read'
    );
  end if;
  v_result := jsonb_set(v_result, '{documents}', v_section);

  -- --------------------------------------------------------------------------
  -- Valuation: the freshness of the case work, never a value. Which figure is
  -- "the" property value is a method decision that METHOD-GOV-01 owns; naming
  -- one here would pre-empt it.
  -- --------------------------------------------------------------------------
  if private.has_workspace_permission(p_workspace_id, 'valuation.read') then
    select jsonb_build_object(
      'available', true,
      'cases_total', count(*),
      'cases_open', count(*) filter (
        where valuation_case.status in ('draft', 'in_review')
      ),
      'last_case_updated_at', max(valuation_case.updated_at)
    )
    into v_section
    from public.valuation_cases as valuation_case
    where valuation_case.workspace_id = p_workspace_id
      and valuation_case.property_id = p_property_id;
  else
    v_section := jsonb_build_object(
      'available', false, 'permission', 'valuation.read'
    );
  end if;
  v_result := jsonb_set(v_result, '{valuation}', v_section);

  -- --------------------------------------------------------------------------
  -- Attention. The server decides what needs attention, with which severity,
  -- and in which order; the client renders that order and never re-scores it.
  --
  -- Every entry is a count of records whose own stored state already says they
  -- are late, urgent or blocked. There is no risk model, no opportunity score
  -- and no completeness percentage here -- those are exactly the client-side
  -- inventions the spec rejects, and they would need definitions this package
  -- does not own.
  --
  -- The list is built from the sections above, so a section the caller may not
  -- read contributes nothing: its counters are null, and null is filtered out.
  -- Attention can therefore never disclose the existence of records behind a
  -- permission the caller lacks.
  -- --------------------------------------------------------------------------
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'type', candidate.attention_type,
               'severity', candidate.severity,
               'count', candidate.item_count,
               'domain', candidate.domain
             )
             order by candidate.severity_rank, candidate.type_rank
           ),
           '[]'::jsonb
         )
  into v_attention
  from (
    values
      -- critical: a deadline that has already passed.
      ('leases_expired_open', 'critical', 'leasing', 1, 1,
       (v_result -> 'leasing' ->> 'leases_expired_open')::integer),
      ('tickets_overdue', 'critical', 'operations', 1, 2,
       (v_result -> 'maintenance' ->> 'tickets_overdue')::integer),
      ('tasks_overdue', 'critical', 'operations', 1, 3,
       (v_result -> 'tasks' ->> 'tasks_overdue')::integer),
      ('requirements_overdue', 'critical', 'documents', 1, 4,
       (v_result -> 'documents' ->> 'requirements_overdue')::integer),
      -- warning: work that is escalated, blocked, or running out of time.
      ('tickets_urgent_open', 'warning', 'operations', 2, 1,
       (v_result -> 'maintenance' ->> 'tickets_urgent_open')::integer),
      ('leases_ending_90d', 'warning', 'leasing', 2, 2,
       (v_result -> 'leasing' ->> 'leases_ending_90d')::integer),
      ('tasks_blocked', 'warning', 'operations', 2, 3,
       (v_result -> 'tasks' ->> 'tasks_blocked')::integer),
      -- info: standing facts worth seeing, not incidents.
      ('units_vacant', 'info', 'leasing', 3, 1,
       (v_result -> 'leasing' ->> 'units_vacant')::integer),
      ('capex_before_approval', 'info', 'operations', 3, 2,
       (v_result -> 'capex' ->> 'projects_before_approval')::integer)
  ) as candidate(
    attention_type, severity, domain, severity_rank, type_rank, item_count
  )
  where candidate.item_count > 0;

  v_result := jsonb_set(v_result, '{attention}', v_attention);

  return jsonb_build_object('ok', true, 'overview', v_result);
end;
$$;

alter function public.property_overview(uuid, uuid) owner to postgres;

revoke all on function public.property_overview(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.property_overview(uuid, uuid)
  to authenticated;
