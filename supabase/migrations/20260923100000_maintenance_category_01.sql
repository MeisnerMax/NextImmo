-- MAINTENANCE-CATEGORY-01 (V-3 of the enterprise operations programme).
--
-- The ticket lists can now be filtered by category, server-side.
--
-- **What was already true, and is why this package is small.** Both list
-- functions aggregate `private.maintenance_ticket_snapshot`, and that snapshot
-- has carried `category` on every row since P2-D06. The value has been sent to
-- every client on every read and used by none of them. What was missing was
-- one predicate and one index — not a column, not a contract.
--
-- **The vocabulary stays free text, deliberately.**
-- `maintenance_tickets.category` is `text` with a length CHECK, and
-- `docs/product/screens/maintenance_tickets.md` §7.2 decides it stays that
-- way: the client carries a curated list and shows an unfamiliar stored value
-- verbatim. An enum would be the tidier schema and the worse product — a
-- workspace that has been categorising its tickets its own way for a year
-- would have that vocabulary silently rejected by a migration, and this filter
-- exists precisely to make sense of what is already there.
--
-- The filter therefore does **not** validate its argument against a list. A
-- category nobody used matches nothing, which is the honest answer; refusing
-- it would claim the server knows the vocabulary, and it does not.
--
-- Both list functions are dropped and recreated because a parameter is added,
-- so the signature changes and the grants move with it. One dropped and one
-- created each, plus one genuinely new read below: SR-20 goes 86 → 87.

-- -----------------------------------------------------------------------------
-- The index the predicate needs
-- -----------------------------------------------------------------------------
--
-- Composite with `workspace_id` rather than on `category` alone: every read is
-- workspace-scoped by RLS as well as by the predicate, so a single-column
-- index would be scanned across tenants and then discarded.
create index maintenance_tickets_category_idx
  on public.maintenance_tickets (workspace_id, category);

-- -----------------------------------------------------------------------------
-- Property-scoped list
-- -----------------------------------------------------------------------------

drop function if exists public.maintenance_tickets(uuid, uuid, uuid, text, text);

create function public.maintenance_tickets(
  p_workspace_id uuid,
  p_property_id uuid,
  p_unit_id uuid default null,
  p_status text default null,
  p_priority text default null,
  p_category text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tickets jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  if p_workspace_id is null or p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace id and property id are required'
      )
    );
  end if;

  if not private.leasing_property_in_workspace(p_workspace_id, p_property_id) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Property not found'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'maintenance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Maintenance tickets are not permitted'
      )
    );
  end if;

  select coalesce(jsonb_agg(private.maintenance_ticket_snapshot(ticket)
                            order by ticket.reported_at desc), '[]'::jsonb)
  into v_tickets
  from public.maintenance_tickets as ticket
  where ticket.workspace_id = p_workspace_id
    and ticket.property_id = p_property_id
    and (p_unit_id is null or ticket.unit_id = p_unit_id)
    and (p_status is null or ticket.status::text = p_status)
    and (p_priority is null or ticket.priority = p_priority)
    -- Trimmed, because the column is trimmed by its own CHECK and a filter
    -- that only matched untrimmed input would look broken rather than strict.
    and (p_category is null or ticket.category = btrim(p_category));

  return jsonb_build_object('ok', true, 'entity', v_tickets);
end;
$function$;

alter function public.maintenance_tickets(uuid, uuid, uuid, text, text, text)
  owner to postgres;
revoke all on function public.maintenance_tickets(uuid, uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.maintenance_tickets(uuid, uuid, uuid, text, text, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- Workspace-wide list
-- -----------------------------------------------------------------------------

drop function if exists public.workspace_maintenance_tickets(uuid, text, text);

create function public.workspace_maintenance_tickets(
  p_workspace_id uuid,
  p_status text default null,
  p_priority text default null,
  p_category text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tickets jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  if p_workspace_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace id is required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'maintenance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Maintenance tickets are not permitted'
      )
    );
  end if;

  select coalesce(jsonb_agg(private.maintenance_ticket_snapshot(ticket)
                            order by ticket.reported_at desc), '[]'::jsonb)
  into v_tickets
  from public.maintenance_tickets as ticket
  where ticket.workspace_id = p_workspace_id
    and (p_status is null or ticket.status::text = p_status)
    and (p_priority is null or ticket.priority = p_priority)
    and (p_category is null or ticket.category = btrim(p_category));

  return jsonb_build_object('ok', true, 'entity', v_tickets);
end;
$function$;

alter function public.workspace_maintenance_tickets(uuid, text, text, text)
  owner to postgres;
revoke all on function public.workspace_maintenance_tickets(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.workspace_maintenance_tickets(uuid, text, text, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- The vocabulary actually in use
-- -----------------------------------------------------------------------------
--
-- A filter is only useful if the reader can see what there is to filter by,
-- and the curated list in the client is a *suggestion* — it cannot know what a
-- workspace has been typing. This returns the distinct categories with their
-- counts, so the filter can offer real values beside the curated ones and say
-- how many tickets each holds.
--
-- Workspace-wide rather than per property: a category that exists on one
-- property is part of the workspace's vocabulary, and offering a different
-- list per property would make the same control mean different things on two
-- screens.
create function public.maintenance_ticket_categories(p_workspace_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_rows jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  if p_workspace_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace id is required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'maintenance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Maintenance tickets are not permitted'
      )
    );
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object('category', entry.category, 'ticket_count', entry.n)
    order by entry.category
  ), '[]'::jsonb)
  into v_rows
  from (
    select ticket.category, count(*) as n
    from public.maintenance_tickets as ticket
    where ticket.workspace_id = p_workspace_id
    group by ticket.category
  ) as entry;

  return jsonb_build_object('ok', true, 'entity', v_rows);
end;
$function$;

alter function public.maintenance_ticket_categories(uuid) owner to postgres;
revoke all on function public.maintenance_ticket_categories(uuid)
  from public, anon, authenticated;
grant execute on function public.maintenance_ticket_categories(uuid)
  to authenticated;

comment on function public.maintenance_ticket_categories(uuid) is
  'Distinct ticket categories in use in a workspace, with counts. The client '
  'carries a curated list (screens/maintenance_tickets.md 7.2); this is what a '
  'workspace has actually been typing, so the filter can offer both.';
