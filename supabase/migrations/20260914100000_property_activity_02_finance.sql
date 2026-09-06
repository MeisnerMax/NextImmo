-- PROPERTY-ACTIVITY-02: the finance domain reaches the object chronicle, and
-- the published event key stops doubling its own prefix.
--
-- Both defects surfaced together the first time the chronicle was pointed at
-- real data (the local demo objects). Neither was visible before, because the
-- pgTAP fixtures for PROPERTY-ACTIVITY-01 invent action strings that no writer
-- in this schema produces.
--
-- -----------------------------------------------------------------------------
-- 1. The finance domain was missing entirely
-- -----------------------------------------------------------------------------
--
-- FINANCE-01a/01b write audit events for accounts, periods, ledger entries and
-- KPI definitions, but `private.property_activity_taxonomy()` predates them and
-- classifies none of those entity types. The chronicle therefore silently
-- omitted every booking and every period close.
--
-- That is worse than a missing feature here. `public.property_activity` returns
-- `visible_domains` precisely so a partial timeline can say so -- the header of
-- PROPERTY-ACTIVITY-01 puts it as "a timeline that covers four of seven domains
-- says so, instead of passing itself off as complete". A domain absent from the
-- taxonomy can never appear in that array, so a reader had no way to tell
-- "no finance activity" from "finance activity is not shown".
--
-- **Only `finance_ledger_entry` is added, and that is the whole honest answer.**
-- Of the five tables FINANCE-01 creates, exactly one carries a `property_id`:
--
--     finance_ledger_entries      property_id uuid not null   -> attributable
--     finance_accounts            (workspace-level)           -> not
--     finance_periods             (workspace-level)           -> not
--     finance_kpi_definitions     (workspace-level)           -> not
--     finance_kpi_definition_lines(workspace-level)           -> not
--
-- Placing a workspace-level record in one property's chronicle would mean every
-- property in the workspace claiming the same event as its own history. Opening
-- a fiscal period is a workspace act; it belongs in a workspace timeline, which
-- does not exist yet and is not invented here.
--
-- The gate is `finance.read`, matching the permission FINANCE-01a added and the
-- one `property_finance_actuals` already enforces. A member without it sees no
-- finance rows AND no `finance` entry in `visible_domains` -- the same
-- permission-shaped coverage statement every other domain already makes.
--
-- Neither `audit_events.parent_entity_type` nor `parent_entity_id` is consulted,
-- because `private.finish_finance_mutation` never sets them (its parameter list
-- has no such columns). Resolution happens at read time through the source
-- table, exactly as it already does for units, leases, tasks and the rest.
--
-- -----------------------------------------------------------------------------
-- 2. `event_key` doubled its prefix on nearly every row
-- -----------------------------------------------------------------------------
--
-- The projection built `entity_type || '.' || action`. An inventory of all 16
-- audit-writing statements in this schema shows 74 of 77 distinct action strings
-- already carry their entity as a prefix, so the result was
-- `lease.lease.transition_status` for essentially every event ever returned.
--
-- The key is now the action itself whenever the action already contains a dot,
-- and the concatenation only where it does not -- which today means only the
-- FINANCE-01 family, the one writer that stores bare verbs.
--
-- `action` and `entity_type` are NOT normalised, here or anywhere. `audit_events`
-- is append-only, so the existing history could not be rewritten even if that
-- were desirable; and imposing a convention going forward would mean touching
-- eight cloned `private.finish_*_mutation` functions plus eight direct writers,
-- and breaking at least nine pgTAP files that pin the strings as they are. The
-- read side tolerates both shapes instead. The client does the same, from the
-- same two fields (`fix/activity-sentence-rendering`).
--
-- No table, column, index, policy, permission or trigger. Three functions are
-- replaced in place, with unchanged signatures, so the public SECURITY DEFINER
-- inventory (SR-20) and the private function inventory are untouched.

-- -----------------------------------------------------------------------------
-- Taxonomy: one new row.
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- Source aggregate: one new resolution branch.
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- Read port: the event key stops doubling.
-- -----------------------------------------------------------------------------

create or replace function public.property_activity(
  p_workspace_id uuid,
  p_property_id uuid,
  p_domains text[] default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_after_occurred_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_actor uuid := auth.uid();
  v_may_name_actors boolean;
  v_visible text[];
  v_requested text[];
  v_events jsonb;
  v_next jsonb;
begin
  if v_actor is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  -- DEC-025.
  if (auth.jwt() ->> 'aal') is distinct from 'aal2' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for the property activity'
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

  if not exists (
    select 1 from public.properties as property
    where property.workspace_id = p_workspace_id
      and property.id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  if p_from is not null and p_to is not null and p_to < p_from then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The period ends before it starts',
        'field', 'to'
      )
    );
  end if;

  -- Which domains this membership may see at all. Computed once; every row is
  -- then filtered against it, so a domain the caller lacks contributes no rows
  -- rather than rows that are hidden afterwards.
  select array_agg(distinct taxonomy.domain order by taxonomy.domain)
  into v_visible
  from private.property_activity_taxonomy() as taxonomy
  where private.has_workspace_permission(
    p_workspace_id, taxonomy.required_permission
  );
  v_visible := coalesce(v_visible, array[]::text[]);

  -- A requested domain the caller cannot see is dropped from the filter rather
  -- than refused: the answer to "show me leasing" without `lease.read` is an
  -- empty leasing timeline, which the coverage list already explains.
  v_requested := case
    when p_domains is null then null
    else coalesce(
      (
        select array_agg(distinct requested.domain order by requested.domain)
        from unnest(p_domains) as requested(domain)
        where requested.domain = any (v_visible)
      ),
      array[]::text[]
    )
  end;

  -- The actor's user id travels only for a caller who already holds the audit
  -- trail, where the same id is published. Everyone else gets the actor type.
  v_may_name_actors := private.has_workspace_permission(
    p_workspace_id, 'audit.read'
  );

  with scoped as (
    select rows.audit_event_id
    from private.property_activity_rows(p_workspace_id, p_property_id) as rows
  ),
  timeline as (
    select
      event.id,
      event.created_at,
      event.action,
      event.entity_type,
      event.entity_id,
      event.actor_type,
      event.actor_user_id,
      taxonomy.domain
    from public.audit_events as event
    join scoped on scoped.audit_event_id = event.id
    join private.property_activity_taxonomy() as taxonomy
      on taxonomy.entity_type = event.entity_type
    where taxonomy.domain = any (v_visible)
      and (v_requested is null or taxonomy.domain = any (v_requested))
      and (p_from is null or event.created_at >= p_from)
      and (p_to is null or event.created_at <= p_to)
      and (
        p_after_occurred_at is null
        or p_after_id is null
        or (event.created_at, event.id) < (p_after_occurred_at, p_after_id)
      )
    order by event.created_at desc, event.id desc
    limit v_limit + 1
  ),
  page as (
    select * from timeline order by created_at desc, id desc limit v_limit
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', page.id,
            'occurred_at', page.created_at,
            'domain', page.domain,
            'entity_type', page.entity_type,
            'entity_id', page.entity_id,
            -- The event key a client renders a sentence from. Built from two
            -- stored columns rather than a stored label, so a new action shows
            -- up as a key instead of vanishing.
            --
            -- Only when the action does not already carry a prefix. Almost
            -- every writer in this schema stores an action qualified with its
            -- own entity (`lease.transition_status`), and the plain
            -- concatenation doubled it into `lease.lease.transition_status`
            -- for every such row -- which is to say, for nearly every row this
            -- function has ever returned.
            'event_key', case
              when position('.' in page.action) > 0 then page.action
              else page.entity_type || '.' || page.action
            end,
            'action', page.action,
            'actor_type', page.actor_type,
            'actor_is_self',
              page.actor_user_id is not null and page.actor_user_id = v_actor,
            'actor_user_id',
              case when v_may_name_actors then page.actor_user_id else null end
          )
          order by page.created_at desc, page.id desc
        )
        from page
      ),
      '[]'::jsonb
    ),
    case
      when (select count(*) from timeline) > v_limit then
        (
          select jsonb_build_object(
            'occurred_at', last_row.created_at, 'id', last_row.id
          )
          from page as last_row
          order by last_row.created_at asc, last_row.id asc
          limit 1
        )
      else null
    end
  into v_events, v_next;

  return jsonb_build_object(
    'ok', true,
    'as_of', now(),
    'events', v_events,
    'next_cursor', v_next,
    -- Coverage, not a hidden count: naming the domains this caller can see
    -- says the timeline is partial without quantifying anyone else's records.
    'visible_domains', to_jsonb(v_visible),
    'actor_names_visible', v_may_name_actors
  );
end;
$function$;
