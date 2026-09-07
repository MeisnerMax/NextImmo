-- LEASING-COMPONENTS-02 (V-2b): the components over time, not on one day.
--
-- `lease_components_as_of` answers "what is payable now". It is the right
-- question for a rent figure and the wrong one for a contract review: it
-- cannot show that the base rent rose twice in three years, that a heating
-- advance was recorded for 2024 and then never again, or that a change was
-- entered with a start date six months in the future. The screen has said
-- "Stand heute" since V-2 precisely because it had no other read to offer.
--
-- **Gaps are reported, but only the interior ones.** The time before the first
-- recorded period is not a gap — nothing was ever claimed about it, and a
-- lease that begins before its components were entered is the normal state of
-- a migrated tenancy, not a defect. Neither is the time after an open-ended
-- last period, which by definition has no after. What *is* a gap is a hole
-- between two recorded periods: somebody stated a figure, stopped, and stated
-- one again. That is a real hole in a real contract, and it is the only kind
-- this function names.
--
-- The distinction is the same one `lease_components_as_of` makes between a
-- type that was never recorded and a type with history that does not cover the
-- date, and it exists for the same reason: reporting absence as a defect
-- teaches people to ignore the report.
--
-- **One lease only, never a property.** A property-scoped history would return
-- every period of every component of every lease in a building — the
-- unbounded read the programme forbids, and unlike the as-of read there is no
-- date to bound it with.
--
-- One new public function: SR-20 89 → 90.

create function public.lease_component_history(
  p_workspace_id uuid,
  p_lease_id uuid,
  p_as_of date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  -- Only decides which period is marked as the current one. The history it
  -- returns is the whole history either way.
  v_as_of date := coalesce(p_as_of, current_date);
  v_lease public.leases%rowtype;
  v_types jsonb;
begin
  if p_workspace_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'Workspace is required',
        'field', 'workspaceId'
      )
    );
  end if;

  if p_lease_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed', 'message', 'A lease is required',
        'field', 'leaseId'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'lease.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Not permitted to read leases'
      )
    );
  end if;

  select lease.* into v_lease
  from public.leases as lease
  where lease.workspace_id = p_workspace_id
    and lease.id = p_lease_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Lease not found'
      )
    );
  end if;

  with component as (
    select *
    from public.lease_components as row
    where row.workspace_id = p_workspace_id
      and row.lease_id = p_lease_id
  ),
  period as (
    select
      component.component_type,
      jsonb_agg(
        jsonb_build_object(
          'id', component.id,
          'valid_from', component.valid_from,
          -- Inclusive, as the column is and as a contract reads. Null is
          -- open-ended, which is the normal state of a current component.
          'valid_to', component.valid_to,
          'amount', component.amount,
          'currency_code', component.currency_code,
          'vat_mode', component.vat_mode,
          'vat_rate_percent', component.vat_rate_percent,
          'note', component.note,
          'version', component.version,
          'updated_at', component.updated_at,
          -- Exactly one period per type can carry this, because the exclusion
          -- constraint forbids two rows covering the same day. A type with
          -- none is one whose history has a hole at this date.
          'in_force', component.validity @> v_as_of
        )
        order by component.valid_from
      ) as periods
    from component
    group by component.component_type
  ),
  span as (
    select
      component.component_type,
      range_agg(component.validity) as covered,
      daterange(
        min(lower(component.validity)),
        -- An open-ended period makes the whole span open-ended, so the
        -- subtraction below can only ever produce interior holes.
        case
          when bool_or(upper_inf(component.validity)) then null
          else max(upper(component.validity))
        end,
        '[)'
      ) as recorded
    from component
    group by component.component_type
  ),
  gap as (
    select
      span.component_type,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'from', lower(hole.range),
            -- Back to inclusive for the API. An interior hole always has a
            -- finite end, because the period after it is what bounds it.
            'to', upper(hole.range) - 1
          )
          order by lower(hole.range)
        ) filter (where hole.range is not null),
        '[]'::jsonb
      ) as holes
    from span
    left join lateral unnest(
      datemultirange(span.recorded) - span.covered
    ) as hole(range) on true
    group by span.component_type
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'component_type', period.component_type,
        'periods', period.periods,
        'gaps', gap.holes
      )
      order by period.component_type
    ),
    '[]'::jsonb
  )
  into v_types
  from period
  join gap on gap.component_type = period.component_type;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'lease_id', p_lease_id,
      'property_id', v_lease.property_id,
      'currency_code', v_lease.currency_code,
      'as_of_date', v_as_of,
      'component_types', v_types
    )
  );
end;
$function$;

alter function public.lease_component_history(uuid, uuid, date) owner to postgres;
revoke all on function public.lease_component_history(uuid, uuid, date)
  from public, anon, authenticated;
grant execute on function public.lease_component_history(uuid, uuid, date)
  to authenticated;

comment on function public.lease_component_history(uuid, uuid, date) is
  'Every recorded period of every component type on one lease, ordered, with '
  'the period in force on p_as_of marked. Reports interior gaps only -- the '
  'time before the first period and after an open-ended last one is not a '
  'gap, because nothing was ever claimed about it. One lease at a time: a '
  'property-scoped history would be an unbounded read.';
