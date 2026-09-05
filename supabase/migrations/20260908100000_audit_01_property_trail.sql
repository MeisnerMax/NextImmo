-- AUDIT-01: the application read port for a property's audit trail.
--
-- `audit_events` has existed since P1-002 and has carried an `audit.read` RLS
-- policy since P1-003, but no application could read it: there was no DTO, no
-- repository and no projection. So every mutation in this system has been
-- audited into a table nobody could open, which is only half of an audit.
--
-- This function is that read port, and the shape of it is the whole point.
--
--   1. **Allowlisted, not "select *".** The row carries `old_values`,
--      `new_values`, `scope_snapshot` — form payloads and permission snapshots
--      that can hold anything a user typed. What travels instead is the *names*
--      of the fields that changed, sorted. "Wer hat wann welches Feld geändert"
--      is the accountability question; "auf welchen Wert" is a separate
--      decision about disclosure, and it is not made here.
--   2. **Two permissions, not one.** `audit.read` says the membership may see
--      the trail; entity-scoped `property.read` says it may see *this*
--      property. Reading an audit record is not weaker than reading the record
--      it describes, and holding `audit.read` must not become a way around an
--      entity scope. The spec is explicit: audit rights do not imply
--      lease/document/valuation rights either, which is why the payload names
--      the target entity but never inlines it.
--   3. **`reason` travels.** It is the operator's own justification for the
--      mutation and is audit metadata rather than record content; an audit
--      trail that hides why something was done answers half the question. The
--      caller already holds `audit.read` on this workspace.
--
-- Child entities reach the property through `parent_entity_*`, which the audit
-- baseline already stamps, so a unit or lease change appears in its property's
-- trail without this read guessing at relationships.
--
-- No new permission, no new policy, no schema change beyond two indexes that
-- exist purely so this read is a lookup rather than a scan.

create index audit_events_entity_trail_idx
  on public.audit_events (
    workspace_id, entity_type, entity_id, created_at desc, id desc
  );

create index audit_events_parent_entity_trail_idx
  on public.audit_events (
    workspace_id, parent_entity_type, parent_entity_id, created_at desc, id desc
  )
  where parent_entity_id is not null;

create function public.property_audit_events(
  p_workspace_id uuid,
  p_property_id uuid,
  p_after_occurred_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_events jsonb;
  v_next jsonb;
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
        'message', 'AAL2 is required for the audit trail'
      )
    );
  end if;

  -- The property first: an entity-scoped membership must not reach another
  -- property's history through the audit door.
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

  if not private.has_workspace_permission(p_workspace_id, 'audit.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Audit access is not permitted'
      )
    );
  end if;

  if not exists (
    select 1
    from public.properties as property
    where property.workspace_id = p_workspace_id
      and property.id = p_property_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'not_found', 'message', 'Property not found')
    );
  end if;

  with trail as (
    select
      event.id,
      event.created_at,
      event.action,
      event.entity_type,
      event.entity_id,
      event.parent_entity_type,
      event.parent_entity_id,
      event.actor_type,
      event.actor_user_id,
      event.actor_identifier,
      event.role_key,
      event.source,
      event.correlation_id,
      event.mutation_id,
      event.reason,
      -- The changed field NAMES, never their values. `old_values` and
      -- `new_values` are per-field patches, so their key sets answer what was
      -- touched without disclosing what it became.
      (
        select coalesce(jsonb_agg(field order by field), '[]'::jsonb)
        from (
          select jsonb_object_keys(coalesce(event.new_values, '{}'::jsonb)) as field
          union
          select jsonb_object_keys(coalesce(event.old_values, '{}'::jsonb))
        ) as fields
      ) as changed_fields
    from public.audit_events as event
    where event.workspace_id = p_workspace_id
      and (
        (event.entity_type = 'property' and event.entity_id = p_property_id)
        or (
          event.parent_entity_type = 'property'
          and event.parent_entity_id = p_property_id
        )
      )
      -- Keyset on (created_at, id): newest first, and stable when two events
      -- share a timestamp.
      and (
        p_after_occurred_at is null
        or p_after_id is null
        or (event.created_at, event.id) < (p_after_occurred_at, p_after_id)
      )
    order by event.created_at desc, event.id desc
    limit v_limit + 1
  ),
  page as (
    select * from trail order by created_at desc, id desc limit v_limit
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', page.id,
            'occurred_at', page.created_at,
            'action', page.action,
            'entity_type', page.entity_type,
            'entity_id', page.entity_id,
            'parent_entity_type', page.parent_entity_type,
            'parent_entity_id', page.parent_entity_id,
            'actor_type', page.actor_type,
            'actor_user_id', page.actor_user_id,
            'actor_identifier', page.actor_identifier,
            'role_key', page.role_key,
            'source', page.source,
            'correlation_id', page.correlation_id,
            'mutation_id', page.mutation_id,
            'reason', page.reason,
            'changed_fields', page.changed_fields
          )
          order by page.created_at desc, page.id desc
        )
        from page
      ),
      '[]'::jsonb
    ),
    case
      when (select count(*) from trail) > v_limit then
        (
          select jsonb_build_object(
            'occurred_at', last_row.created_at,
            'id', last_row.id
          )
          from (
            select created_at, id from page order by created_at, id limit 1
          ) as last_row
        )
      else null
    end
  into v_events, v_next;

  return jsonb_build_object(
    'ok', true,
    'events', v_events,
    'next_cursor', v_next
  );
end;
$$;

alter function public.property_audit_events(uuid, uuid, timestamptz, uuid, integer)
  owner to postgres;

revoke all on function public.property_audit_events(uuid, uuid, timestamptz, uuid, integer)
  from public, anon, authenticated;

grant execute on function public.property_audit_events(uuid, uuid, timestamptz, uuid, integer)
  to authenticated;
