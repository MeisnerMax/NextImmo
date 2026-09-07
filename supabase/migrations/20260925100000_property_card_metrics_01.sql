-- PROPERTY-CARD-METRICS-01 (P-1b of the enterprise property programme).
--
-- The property cards show a name, a status and nothing else, because the only
-- read that knows the operational numbers — `property_overview` — answers for
-- one property at a time. Forty cards would be forty round trips, so the list
-- has stayed uninformative rather than become slow. This is the batch read
-- that removes the choice.
--
-- **It reports the same numbers as the overview, by design and by test.**
-- The expressions below are the overview's, repeated rather than shared: the
-- alternative was to drop and recreate a 350-line security-sensitive function
-- to extract two helpers, which is a refactor this package does not need to
-- own. The duplication is therefore pinned instead of structured away —
-- `049_property_card_metrics_01.test.sql` asserts field by field that the
-- batch and the overview agree for the same property, so a future edit to one
-- of them fails CI rather than quietly making a card disagree with the detail
-- screen it links to.
--
-- **No rate, no NOI, and that is the same decision the overview already made.**
-- A card is exactly where an occupancy percentage would be tempting, and
-- exactly where it would be wrong: by unit or by area is an owner decision
-- nobody has taken (it is still open in the programme), and the two answers
-- differ for every mixed-use asset. So the constituents are reported —
-- occupied and total — and the reader can see the fraction without the server
-- pretending to know which denominator the workspace means. Net operating
-- income needs the finance contract that does not exist yet; an invented one
-- on a card would be the most quoted wrong number in the product.
--
-- **What is withheld is not distinguished from what is absent.** An id that
-- names no property and an id the caller may not see both land in `withheld`.
-- Splitting them would answer "does this property exist" for someone the
-- entity scope says may not know, which is the leak `has_scoped_entity_
-- permission` exists to prevent.
--
-- The id list is capped. An uncapped `= any (...)` is a way to ask one
-- statement to scan the whole tenant, and a paged card grid never needs more
-- than a page.
--
-- One new public function: SR-20 88 → 89.

create function public.property_card_metrics(
  p_workspace_id uuid,
  p_property_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_now timestamptz := now();
  v_today date := (v_now at time zone 'utc')::date;
  v_ids uuid[];
  v_permitted uuid[];
  v_may_lease boolean;
  v_may_maintenance boolean;
  v_rows jsonb;
  v_withheld jsonb;
  -- A page of cards, generously. Beyond this the caller is not rendering a
  -- grid, it is exporting, and that wants its own contract.
  c_max_ids constant integer := 200;
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
        'code', 'forbidden', 'message', 'AAL2 is required for property metrics'
      )
    );
  end if;

  if p_workspace_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace is required',
        'field', 'workspaceId'
      )
    );
  end if;

  if p_property_ids is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Property ids are required',
        'field', 'propertyIds'
      )
    );
  end if;

  -- Nulls dropped and duplicates collapsed before the cap is measured: a
  -- caller that repeated an id forty times asked for one property.
  select coalesce(array_agg(distinct entry.id), array[]::uuid[])
  into v_ids
  from unnest(p_property_ids) as entry(id)
  where entry.id is not null;

  if cardinality(v_ids) > c_max_ids then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', format('At most %s properties can be read at once',
                          c_max_ids),
        'field', 'propertyIds'
      )
    );
  end if;

  -- Entity scope decides membership, one property at a time, exactly as the
  -- single-property overview does. Everything downstream reads only these.
  select coalesce(array_agg(property.id order by property.id), array[]::uuid[])
  into v_permitted
  from public.properties as property
  where property.workspace_id = p_workspace_id
    and property.id = any (v_ids)
    and private.has_scoped_entity_permission(
          p_workspace_id, 'property.read', 'property', property.id
        );

  v_may_lease := private.has_workspace_permission(p_workspace_id, 'lease.read');
  v_may_maintenance :=
    private.has_workspace_permission(p_workspace_id, 'maintenance.read');

  with permitted as (
    select entry.id from unnest(v_permitted) as entry(id)
  ),
  -- Each section's rows are read only when its permission is held. The outer
  -- CASE would discard them anyway, but a read that happens and is then thrown
  -- away is still a read of records the caller may not see.
  unit_stats as (
    select
      unit.property_id,
      count(*) as units_total,
      count(*) filter (where unit.status = 'occupied') as units_occupied,
      count(*) filter (where unit.status = 'vacant') as units_vacant,
      count(*) filter (where unit.status = 'offline') as units_offline
    from public.units as unit
    join permitted on permitted.id = unit.property_id
    where v_may_lease
      and unit.workspace_id = p_workspace_id
    group by unit.property_id
  ),
  lease_stats as (
    select
      lease.property_id,
      count(*) filter (where lease.status = 'active') as leases_active,
      count(*) filter (
        where lease.status = 'active'
          and lease.end_date is not null
          and lease.end_date between v_today and (v_today + 90)
      ) as leases_ending_90d,
      count(*) filter (
        where lease.status = 'active'
          and lease.end_date is not null
          and lease.end_date < v_today
      ) as leases_expired_open
    from public.leases as lease
    join permitted on permitted.id = lease.property_id
    where v_may_lease
      and lease.workspace_id = p_workspace_id
    group by lease.property_id
  ),
  case_stats as (
    select
      leasing_case.property_id,
      count(*) filter (
        where leasing_case.status not in ('completed', 'cancelled')
      ) as leasing_cases_open
    from public.leasing_cases as leasing_case
    join permitted on permitted.id = leasing_case.property_id
    where v_may_lease
      and leasing_case.workspace_id = p_workspace_id
    group by leasing_case.property_id
  ),
  ticket_stats as (
    select
      ticket.property_id,
      count(*) filter (
        where ticket.status not in ('resolved', 'invoiced', 'archived')
      ) as tickets_open,
      count(*) filter (
        where ticket.status not in ('resolved', 'invoiced', 'archived')
          and ticket.due_at is not null
          and ticket.due_at < v_now
      ) as tickets_overdue,
      count(*) filter (
        where ticket.status not in ('resolved', 'invoiced', 'archived')
          and ticket.priority = 'urgent'
      ) as tickets_urgent_open
    from public.maintenance_tickets as ticket
    join permitted on permitted.id = ticket.property_id
    where v_may_maintenance
      and ticket.workspace_id = p_workspace_id
    group by ticket.property_id
  )
  select coalesce(jsonb_agg(card.payload order by card.id), '[]'::jsonb)
  into v_rows
  from (
    select
      permitted.id,
      jsonb_build_object(
        'property_id', permitted.id,
        'leasing', case
          when v_may_lease then jsonb_build_object(
            'available', true,
            -- coalesce, because "this property has no units" is a real answer
            -- and the outer join gives it as null.
            'units_total', coalesce(unit_stats.units_total, 0),
            'units_occupied', coalesce(unit_stats.units_occupied, 0),
            'units_vacant', coalesce(unit_stats.units_vacant, 0),
            'units_offline', coalesce(unit_stats.units_offline, 0),
            'leases_active', coalesce(lease_stats.leases_active, 0),
            'leases_ending_90d', coalesce(lease_stats.leases_ending_90d, 0),
            'leases_expired_open', coalesce(lease_stats.leases_expired_open, 0),
            'leasing_cases_open', coalesce(case_stats.leasing_cases_open, 0)
          )
          else jsonb_build_object('available', false, 'permission', 'lease.read')
        end,
        'maintenance', case
          when v_may_maintenance then jsonb_build_object(
            'available', true,
            'tickets_open', coalesce(ticket_stats.tickets_open, 0),
            'tickets_overdue', coalesce(ticket_stats.tickets_overdue, 0),
            'tickets_urgent_open', coalesce(ticket_stats.tickets_urgent_open, 0)
          )
          else jsonb_build_object(
            'available', false, 'permission', 'maintenance.read'
          )
        end
      ) as payload
    from permitted
    left join unit_stats on unit_stats.property_id = permitted.id
    left join lease_stats on lease_stats.property_id = permitted.id
    left join case_stats on case_stats.property_id = permitted.id
    left join ticket_stats on ticket_stats.property_id = permitted.id
  ) as card;

  select coalesce(jsonb_agg(to_jsonb(entry.id) order by entry.id), '[]'::jsonb)
  into v_withheld
  from unnest(v_ids) as entry(id)
  where not (entry.id = any (v_permitted));

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      -- Travels with the payload, like the overview's, so a card can say how
      -- old its numbers are instead of implying they are live.
      'as_of', v_now,
      'properties', v_rows,
      'withheld', v_withheld
    )
  );
end;
$function$;

alter function public.property_card_metrics(uuid, uuid[]) owner to postgres;

revoke all on function public.property_card_metrics(uuid, uuid[])
  from public, anon, authenticated;

grant execute on function public.property_card_metrics(uuid, uuid[])
  to authenticated;

comment on function public.property_card_metrics(uuid, uuid[]) is
  'Card metrics for a page of properties in one read: the leasing and '
  'maintenance counts property_overview reports, batched so a grid needs one '
  'round trip instead of one per card. Ids that name nothing and ids the '
  'entity scope withholds are reported together in withheld, deliberately '
  'indistinguishable. No occupancy rate and no NOI: both need definitions '
  'nobody has taken.';
