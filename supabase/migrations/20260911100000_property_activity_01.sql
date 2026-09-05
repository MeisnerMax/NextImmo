-- PROPERTY-ACTIVITY-01: the readable chronicle of what happened to a property.
--
-- `AUDIT-01` gave the forensic trail: who touched which field, gated on
-- `audit.read`. This is the other half `PROPERTY_ACTIVITY_V2.md` asks for — a
-- chronicle an asset manager can read without audit rights, showing business
-- events rather than field names, and gated per row on the *domain* permission
-- of the record each event is about.
--
-- Three things had to be decided before it could exist.
--
-- **1. How a child record reaches its property.**
--
-- `audit_events` carries `parent_entity_type`/`parent_entity_id`, and the
-- AUDIT-01 header assumed the domains stamp it. They do not: of the twelve
-- migrations that write audit rows, only property media and the notification
-- emitter set a parent. Every unit, lease, ticket, CapEx project, document and
-- valuation change is audited with no property link at all — which is why a
-- property's audit trail today shows property and media events and nothing
-- else.
--
-- Two ways to fix that. Stamping the parent from now on would leave every row
-- already written unreachable, and would touch eleven mutation paths. Instead
-- `private.property_activity_rows` resolves the property at *read* time
-- through the source aggregate — `units.property_id`, `leases.property_id`,
-- `document_links` for documents, and so on. That reaches the history that
-- already exists, changes no write path, and keeps the mapping in one place
-- where it can be tested.
--
-- This function does **not** widen `property_audit_events`. Letting `audit.read`
-- alone reveal which fields of a lease changed is a disclosure decision the
-- spec explicitly defers to a security review, and widening it quietly here
-- would make that decision by accident.
--
-- **2. What a row is allowed to say.**
--
-- No values, no changed field names, no `reason`. `reason` is the operator's
-- free text and `PROPERTY_ACTIVITY_V2.md` §7 rules free text out; field names
-- are the audit trail's job and its gate. What travels is the event: which
-- domain, which kind of record, what happened to it, when, and enough of a
-- reference to open the source if the caller may.
--
-- Actor identity is the same question. The spec says actor visibility needs an
-- approved contract and that `audit.read` must not be assumed. So a row always
-- carries the actor *type*, and says whether it was the caller themselves; the
-- actor's user id travels only for a caller who already holds `audit.read` and
-- could read it from the trail anyway. No new disclosure is invented here.
--
-- **3. What happens to a record the caller may not read.**
--
-- It is excluded server-side, not hidden client-side. And rather than
-- publishing how many events were withheld — a count of other people's records
-- is still a disclosure — the payload names the domains this caller *can* see.
-- A timeline that covers four of seven domains says so, instead of passing
-- itself off as the whole history.
--
-- An entity type that is not in the taxonomy is excluded as well. Fail closed:
-- an unmapped type has no known permission, and guessing one is how an audit
-- row about a membership ends up in a property chronicle.

-- -----------------------------------------------------------------------------
-- Taxonomy: entity type -> domain, required permission.
--
-- A function rather than a table on purpose. This is a code-level contract
-- between the audit writers and this read, not workspace data: a workspace
-- must not be able to grant itself visibility by inserting a row.
-- -----------------------------------------------------------------------------

create function private.property_activity_taxonomy()
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
    ('valuation_case', 'valuation', 'valuation.read')
$function$;

alter function private.property_activity_taxonomy() owner to postgres;
revoke all on function private.property_activity_taxonomy()
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Property resolution per entity type.
--
-- One branch per source table. Verbose on purpose: a generic join over any
-- column named `property_id` would silently pick up a future table with that
-- name whose rows have nothing to do with this chronicle.
-- -----------------------------------------------------------------------------

create function private.property_activity_rows(
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
    )
$function$;

alter function private.property_activity_rows(uuid, uuid) owner to postgres;
revoke all on function private.property_activity_rows(uuid, uuid)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- The read port.
-- -----------------------------------------------------------------------------

create function public.property_activity(
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
            'event_key', page.entity_type || '.' || page.action,
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

alter function public.property_activity(
  uuid, uuid, text[], timestamptz, timestamptz, timestamptz, uuid, integer
) owner to postgres;

revoke all on function public.property_activity(
  uuid, uuid, text[], timestamptz, timestamptz, timestamptz, uuid, integer
) from public, anon, authenticated;

grant execute on function public.property_activity(
  uuid, uuid, text[], timestamptz, timestamptz, timestamptz, uuid, integer
) to authenticated;
